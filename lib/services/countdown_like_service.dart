import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'unified_analytics_service.dart';
import 'mvp_analytics_client.dart';

class CountdownLikeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'countdownLikes';

  // ユーザーがカウントダウンにいいねしているかチェック
  static Future<bool> isLiked(String countdownId, String userId) async {
    try {
      final doc = await _firestore
          .collection(_collection)
          .doc('${countdownId}_$userId')
          .get();
      return doc.exists;
    } catch (e) {
      print('Error checking like status: $e');
      return false;
    }
  }

  // いいねをトグル（いいね/いいね解除）
  static Future<bool> toggleLike(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('ユーザーがログインしていません');
    }

    final userId = user.uid;
    final likeId = '${countdownId}_$userId';
    
    try {
      final likeDoc = _firestore.collection(_collection).doc(likeId);
      final docSnapshot = await likeDoc.get();
      
      if (docSnapshot.exists) {
        // 🚀 統一パイプライン: いいね削除イベント送信（Firestore更新はサーバーサイドで実行）
        final success = await UnifiedAnalyticsService.sendLikeEvent(countdownId, false);
        return success ? false : docSnapshot.exists; // 成功時はfalse（削除）、失敗時は元の状態
      } else {
        // 🚀 統一パイプライン: いいね追加イベント送信（Firestore更新はサーバーサイドで実行）
        final success = await UnifiedAnalyticsService.sendLikeEvent(countdownId, true);
        return success ? true : false; // 成功時はtrue（追加）、失敗時はfalse
      }
    } catch (e) {
      print('Error toggling like: $e');
      throw Exception('いいねの処理に失敗しました');
    }
  }

  // 【超高速】Redis集計済みいいね数を取得
  static Future<int> getLikesCount(String countdownId) async {
    try {
      // 🚀 統一パイプライン: 1-5ms超高速レスポンス
      return await MVPAnalyticsClient.getCounterValue(
        countdownId: countdownId,
        counterType: 'likes',
      );
    } catch (e) {
      print('CountdownLikeService - Error getting likes count: $e');
      return 0;
    }
  }

  // ユーザーがいいねしたカウントダウンのリストを取得
  static Future<List<String>> getUserLikes(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .get();
      
      return snapshot.docs.map((doc) => doc.data()['countdownId'] as String).toList();
    } catch (e) {
      print('Error getting user likes: $e');
      return [];
    }
  }

  // いいねしたユーザーのリストを取得
  static Future<List<String>> getCountdownLikes(String countdownId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('countdownId', isEqualTo: countdownId)
          .get();
      
      return snapshot.docs.map((doc) => doc.data()['userId'] as String).toList();
    } catch (e) {
      print('Error getting countdown likes: $e');
      return [];
    }
  }
}