import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'simple_firestore_service.dart';

/// ライクサービス (Phase0 - Firestore only)
/// 
/// SimpleFirestoreServiceを直接使用し、マイクロサービス依存を排除
class ScalableLikeService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// いいねの切り替え
  static Future<bool> toggleLike(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    try {
      final isCurrentlyLiked = await SimpleFirestoreService.isLiked(countdownId);
      
      if (isCurrentlyLiked) {
        await SimpleFirestoreService.unlikePost(countdownId);
      } else {
        await SimpleFirestoreService.likePost(countdownId);
      }
      
      return !isCurrentlyLiked;
      
    } catch (e) {
      print('ScalableLikeService - Error toggling like: $e');
      throw Exception('いいね処理に失敗しました: $e');
    }
  }

  /// いいね状態の確認
  static Future<bool> isLiked(String countdownId, String userId) async {
    try {
      return await SimpleFirestoreService.isLiked(countdownId);
    } catch (e) {
      print('ScalableLikeService - Error checking like status: $e');
      return false;
    }
  }

  /// いいね数を取得 (Firestoreから直接取得)
  static Future<int> getLikesCount(String countdownId) async {
    try {
      final postDoc = await _firestore.collection('posts').doc(countdownId).get();
      if (postDoc.exists) {
        return postDoc.data()?['likesCount'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('ScalableLikeService - Error getting likes count: $e');
      return 0;
    }
  }

  /// ユーザーのいいね一覧を取得
  static Future<List<String>> getUserLikedCountdowns(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('likes')
          .where('userId', isEqualTo: userId)
          .get();
      
      return snapshot.docs
          .map((doc) => doc.data()['postId'] as String)
          .toList();
    } catch (e) {
      print('ScalableLikeService - Error getting user likes: $e');
      return [];
    }
  }
}