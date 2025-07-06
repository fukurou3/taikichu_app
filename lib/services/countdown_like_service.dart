import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'countdown_service.dart';

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
        // いいね解除（Cloud Functionsがカウントを自動更新）
        await likeDoc.delete();
        return false;
      } else {
        // いいね追加（Cloud Functionsがカウントを自動更新）
        await likeDoc.set({
          'countdownId': countdownId,
          'userId': userId,
          'createdAt': Timestamp.now(),
        });
        return true;
      }
    } catch (e) {
      print('Error toggling like: $e');
      throw Exception('いいねの処理に失敗しました');
    }
  }

  // カウントダウンのいいね数を取得
  static Future<int> getLikesCount(String countdownId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('countdownId', isEqualTo: countdownId)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting likes count: $e');
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