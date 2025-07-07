import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cost_safe_counter_service.dart';
import 'scalable_trend_service.dart';

/// スケーラブルなライクサービス
/// 
/// 分散カウンターとイベント駆動型トレンド更新に対応
/// 大量のいいねが集中してもFirestore書き込み上限に引っかからない
class ScalableLikeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// いいねの切り替え（分散カウンター対応）
  static Future<bool> toggleLike(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    try {
      // いいね状態を確認・更新
      final likeRef = _firestore
          .collection('likes')
          .doc('${countdownId}_${user.uid}');

      return await _firestore.runTransaction((transaction) async {
        final likeSnapshot = await transaction.get(likeRef);
        final isCurrentlyLiked = likeSnapshot.exists;
        
        if (isCurrentlyLiked) {
          // いいね解除
          transaction.delete(likeRef);
          
          // 【安全】分散カウンターをデクリメント
          await CostSafeCounterService.incrementCounter(
            countdownId: countdownId,
            counterType: 'likes',
            increment: -1,
          );
          
          // トレンドスコア更新
          await ScalableTrendService.updateTrendScoreOnAction(
            countdownId: countdownId,
            actionType: 'like',
            increment: -1,
          );
          
          return false;
        } else {
          // いいね追加
          transaction.set(likeRef, {
            'countdownId': countdownId,
            'userId': user.uid,
            'likedAt': FieldValue.serverTimestamp(),
          });
          
          // 【安全】分散カウンターをインクリメント
          await CostSafeCounterService.incrementCounter(
            countdownId: countdownId,
            counterType: 'likes',
            increment: 1,
          );
          
          // トレンドスコア更新
          await ScalableTrendService.updateTrendScoreOnAction(
            countdownId: countdownId,
            actionType: 'like',
            increment: 1,
          );
          
          return true;
        }
      });
      
    } catch (e) {
      print('ScalableLikeService - Error toggling like: $e');
      throw Exception('いいね処理に失敗しました: $e');
    }
  }

  /// いいね状態の確認
  static Future<bool> isLiked(String countdownId, String userId) async {
    try {
      final doc = await _firestore
          .collection('likes')
          .doc('${countdownId}_$userId')
          .get();
      return doc.exists;
    } catch (e) {
      print('ScalableLikeService - Error checking like status: $e');
      return false;
    }
  }

  /// 【安全・高速】集計済みいいね数を取得
  /// 
  /// 🎯 10シャードを毎回読み取る代わりに、集計済み値を1回で取得
  /// 💰 コストを90%削減
  static Future<int> getLikesCount(String countdownId) async {
    return await CostSafeCounterService.getCounterValue(
      countdownId: countdownId,
      counterType: 'likes',
    );
  }

  /// 【緊急時のみ】シャード直接読み取り
  /// 
  /// ⚠️ 集計が遅れている場合の最後の手段
  /// ⚠️ 高コストのため多用禁止
  static Future<int> getLikesCountDirect(String countdownId) async {
    return await CostSafeCounterService.getCounterValueDirect(
      countdownId: countdownId,
      counterType: 'likes',
    );
  }

  /// ユーザーのいいね一覧を取得
  static Future<List<String>> getUserLikedCountdowns(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('likes')
          .where('userId', isEqualTo: userId)
          .get();
      
      return snapshot.docs
          .map((doc) => doc.data()['countdownId'] as String)
          .toList();
    } catch (e) {
      print('ScalableLikeService - Error getting user likes: $e');
      return [];
    }
  }

  /// 特定カウントダウンのいいねユーザー一覧
  static Future<List<Map<String, dynamic>>> getCountdownLikers(
    String countdownId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('likes')
          .where('countdownId', isEqualTo: countdownId)
          .orderBy('likedAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => {
                'userId': doc.data()['userId'],
                'likedAt': doc.data()['likedAt'],
              })
          .toList();
    } catch (e) {
      print('ScalableLikeService - Error getting likers: $e');
      return [];
    }
  }
}