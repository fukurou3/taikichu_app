import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';
import '../models/trend_ranking.dart';
import 'comment_service.dart';
import 'countdown_service.dart';

class TrendRankingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<List<TrendRanking>> getTrendRankings({
    RankingType type = RankingType.overall,
    int limit = 10,
  }) async {
    try {
      // 事前計算されたランキングデータを取得
      Query<Map<String, dynamic>> query = _firestore.collection('trendRankings');
      
      // カテゴリフィルター
      if (type != RankingType.overall) {
        query = query.where('category', isEqualTo: type.categoryFilter);
      }
      
      query = query.orderBy('rank').limit(limit);
      
      final snapshot = await query.get();
      
      if (snapshot.docs.isEmpty) {
        // ランキングデータが存在しない場合、リアルタイムで計算
        return await _calculateRankingsRealtime(type: type, limit: limit);
      }
      
      final rankings = snapshot.docs.map((doc) {
        final data = doc.data();
        return TrendRanking(
          countdownId: data['countdownId'] as String,
          eventName: data['eventName'] as String,
          category: data['category'] as String,
          eventDate: (data['eventDate'] as Timestamp).toDate(),
          participantsCount: data['participantsCount'] as int,
          commentsCount: data['commentsCount'] as int,
          sharesCount: data['sharesCount'] as int,
          trendScore: (data['trendScore'] as num).toDouble(),
          rank: data['rank'] as int,
        );
      }).toList();

      return rankings;
    } catch (e) {
      print('Error fetching trend rankings: $e');
      // エラーの場合はリアルタイム計算にフォールバック
      return await _calculateRankingsRealtime(type: type, limit: limit);
    }
  }

  static Future<List<TrendRanking>> _calculateRankingsRealtime({
    RankingType type = RankingType.overall,
    int limit = 10,
  }) async {
    try {
      // 全てのカウントダウンを取得（正しいコレクション名を使用）
      Query<Map<String, dynamic>> query = _firestore.collection('counts');
      
      // カテゴリフィルター
      if (type != RankingType.overall) {
        query = query.where('category', isEqualTo: type.categoryFilter);
      }
      
      final snapshot = await query.get();
      final countdowns = snapshot.docs.map((doc) {
        return Countdown.fromFirestore(doc, null);
      }).toList();

      // 各カウントダウンのトレンドスコアを計算
      final List<TrendRanking> rankings = [];
      
      for (final countdown in countdowns) {
        final commentsCount = await CommentService.getCommentCount(countdown.id);
        final sharesCount = await _getSharesCount(countdown.id);
        final trendScore = _calculateTrendScore(
          countdown.participantsCount,
          commentsCount,
          sharesCount,
          countdown.eventDate,
        );
        
        rankings.add(TrendRanking.fromCountdown(
          countdown,
          commentsCount,
          sharesCount,
          trendScore,
          0, // ランクは後で設定
        ));
      }

      // トレンドスコアでソート
      rankings.sort((a, b) => b.trendScore.compareTo(a.trendScore));

      // ランクを設定
      for (int i = 0; i < rankings.length; i++) {
        rankings[i] = TrendRanking(
          countdownId: rankings[i].countdownId,
          eventName: rankings[i].eventName,
          category: rankings[i].category,
          eventDate: rankings[i].eventDate,
          participantsCount: rankings[i].participantsCount,
          commentsCount: rankings[i].commentsCount,
          sharesCount: rankings[i].sharesCount,
          trendScore: rankings[i].trendScore,
          rank: i + 1,
        );
      }

      return rankings.take(limit).toList();
    } catch (e) {
      print('Error calculating realtime rankings: $e');
      return [];
    }
  }

  // ランキングデータを事前計算してFirestoreに保存
  static Future<void> updateRankings() async {
    try {
      // 全カテゴリのランキングを計算
      for (final type in RankingType.values) {
        final rankings = await _calculateRankingsRealtime(type: type, limit: 50);
        
        // 既存のランキングデータを削除
        final existingQuery = _firestore
            .collection('trendRankings')
            .where('category', isEqualTo: type == RankingType.overall ? 'overall' : type.categoryFilter);
        
        final existingDocs = await existingQuery.get();
        for (final doc in existingDocs.docs) {
          await doc.reference.delete();
        }
        
        // 新しいランキングデータを保存
        for (final ranking in rankings) {
          await _firestore.collection('trendRankings').add({
            'countdownId': ranking.countdownId,
            'eventName': ranking.eventName,
            'category': type == RankingType.overall ? 'overall' : ranking.category,
            'eventDate': Timestamp.fromDate(ranking.eventDate),
            'participantsCount': ranking.participantsCount,
            'commentsCount': ranking.commentsCount,
            'sharesCount': ranking.sharesCount,
            'trendScore': ranking.trendScore,
            'rank': ranking.rank,
            'updatedAt': Timestamp.now(),
          });
        }
      }
      
      print('Trend rankings updated successfully');
    } catch (e) {
      print('Error updating trend rankings: $e');
    }
  }

  static double _calculateTrendScore(
    int participantsCount,
    int commentsCount,
    int sharesCount,
    DateTime eventDate,
  ) {
    // 基本スコア：参加者数 × 1.0 + コメント数 × 2.0 + シェア数 × 3.0
    double baseScore = participantsCount * 1.0 + commentsCount * 2.0 + sharesCount * 3.0;
    
    // 時間による重み付け
    final now = DateTime.now();
    final daysUntilEvent = eventDate.difference(now).inDays;
    
    double timeWeight = 1.0;
    if (daysUntilEvent <= 1) {
      timeWeight = 3.0; // 開催直前は3倍
    } else if (daysUntilEvent <= 3) {
      timeWeight = 2.0; // 3日前までは2倍
    } else if (daysUntilEvent <= 7) {
      timeWeight = 1.5; // 1週間前までは1.5倍
    }
    
    // 過去のイベントは重みを下げる
    if (daysUntilEvent < 0) {
      timeWeight = 0.1;
    }

    return baseScore * timeWeight;
  }

  static Future<int> _getSharesCount(String countdownId) async {
    // 現在はシェア機能が未実装なので0を返す
    // 今後実装時はここでFirestoreから取得
    return 0;
  }

  static Stream<List<TrendRanking>> getTrendRankingsStream({
    RankingType type = RankingType.overall,
    int limit = 10,
  }) {
    // リアルタイム更新のためのStreamを返す
    return Stream.periodic(const Duration(minutes: 5), (count) => count)
        .asyncMap((_) => getTrendRankings(type: type, limit: limit));
  }

  /// カテゴリ別のカウントダウンをトレンド順で取得
  static Future<List<Countdown>> getCountdownsByCategory({
    required String category,
    int limit = 20,
  }) async {
    try {
      // まずトレンドランキングから取得を試みる
      Query<Map<String, dynamic>> rankingQuery = _firestore.collection('trendRankings');
      
      if (category != 'overall') {
        rankingQuery = rankingQuery.where('category', isEqualTo: category);
      }
      
      rankingQuery = rankingQuery.orderBy('rank').limit(limit);
      
      final rankingSnapshot = await rankingQuery.get();
      
      if (rankingSnapshot.docs.isNotEmpty) {
        // トレンドランキングからカウントダウンIDを取得
        final countdownIds = rankingSnapshot.docs
            .map((doc) => doc.data()['countdownId'] as String)
            .toList();
        
        // 各カウントダウンの詳細データを取得
        final List<Countdown> countdowns = [];
        for (final id in countdownIds) {
          try {
            final countdownDoc = await _firestore.collection('counts').doc(id).get();
            if (countdownDoc.exists) {
              countdowns.add(Countdown.fromFirestore(countdownDoc, null));
            }
          } catch (e) {
            print('Error fetching countdown $id: $e');
          }
        }
        
        return countdowns;
      } else {
        // トレンドランキングがない場合、直接カウントダウンを取得してソート
        return await _getCountdownsByCategoryDirect(category: category, limit: limit);
      }
    } catch (e) {
      print('Error getting countdowns by category: $e');
      return await _getCountdownsByCategoryDirect(category: category, limit: limit);
    }
  }

  /// カテゴリ別のカウントダウンを直接取得（フォールバック用）
  static Future<List<Countdown>> _getCountdownsByCategoryDirect({
    required String category,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore.collection('counts');
      
      if (category != 'overall') {
        query = query.where('category', isEqualTo: category);
      }
      
      // 最近の活動順でソート（recentCommentsCount + recentLikesCount + recentViewsCountの合計）
      query = query.orderBy('eventDate', descending: false).limit(limit * 2); // 多めに取得してソート
      
      final snapshot = await query.get();
      final countdowns = snapshot.docs.map((doc) {
        final data = doc.data();
        return Countdown(
          id: doc.id,
          eventName: data['eventName'] as String,
          description: data['description'] as String?,
          eventDate: (data['eventDate'] as Timestamp).toDate(),
          category: data['category'] as String,
          imageUrl: data['imageUrl'] as String?,
          creatorId: data['creatorId'] as String,
          participantsCount: data['participantsCount'] as int? ?? 0,
          likesCount: data['likesCount'] as int? ?? 0,
          commentsCount: data['commentsCount'] as int? ?? 0,
          viewsCount: data['viewsCount'] as int? ?? 0,
          recentCommentsCount: data['recentCommentsCount'] as int? ?? 0,
          recentLikesCount: data['recentLikesCount'] as int? ?? 0,
          recentViewsCount: data['recentViewsCount'] as int? ?? 0,
          commentCount: data['commentCount'] as int? ?? data['commentsCount'] as int? ?? 0,
        );
      }).toList();

      // トレンドスコア順でソート
      countdowns.sort((a, b) {
        final aScore = (a.participantsCount * 5.0) + 
                      (a.recentViewsCount * 3.0) + 
                      (a.recentCommentsCount * 2.0) + 
                      (a.recentLikesCount * 1.5);
        final bScore = (b.participantsCount * 5.0) + 
                      (b.recentViewsCount * 3.0) + 
                      (b.recentCommentsCount * 2.0) + 
                      (b.recentLikesCount * 1.5);
        return bScore.compareTo(aScore);
      });

      return countdowns.take(limit).toList();
    } catch (e) {
      print('Error getting countdowns directly: $e');
      return [];
    }
  }
}