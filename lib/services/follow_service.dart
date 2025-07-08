// Simplified Follow Service for Phase0 v2.1
// Direct Firestore operations without complex caching

import 'package:firebase_auth/firebase_auth.dart';
import 'simple_firestore_service.dart';

class FollowService {
  /// フォロー/アンフォローの切り替え
  static Future<void> toggleFollow(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // 現在のフォロー状態確認
      final isCurrentlyFollowing = await isFollowing(targetUserId);
      
      if (isCurrentlyFollowing) {
        await SimpleFirestoreService.unfollowUser(targetUserId);
      } else {
        await SimpleFirestoreService.followUser(targetUserId);
      }

      print('FollowService - Toggle follow completed for user: $targetUserId');
    } catch (e) {
      print('FollowService - Error toggling follow: $e');
      rethrow;
    }
  }

  /// フォロー状態確認
  static Future<bool> isFollowing(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      return await SimpleFirestoreService.isFollowing(user.uid, targetUserId);
    } catch (e) {
      print('FollowService - Error checking follow state: $e');
      return false;
    }
  }

  /// フォロー数取得
  static Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      return await SimpleFirestoreService.getFollowCounts(userId);
    } catch (e) {
      print('FollowService - Error getting follow counts: $e');
      return {'following': 0, 'followers': 0};
    }
  }

  /// フォロワーリスト取得 (簡易版)
  static Future<List<String>> getFollowers(String userId) async {
    try {
      // Note: SimpleFirestoreService doesn't have this method yet
      // This is a placeholder for now
      return [];
    } catch (e) {
      print('FollowService - Error getting followers: $e');
      return [];
    }
  }
}