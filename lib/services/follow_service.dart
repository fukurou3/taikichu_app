import 'package:firebase_auth/firebase_auth.dart';
import 'unified_analytics_service.dart';
import 'mvp_analytics_client.dart';

class FollowService {
  static Future<void> toggleFollow(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // 統一パイプライン経由でフォロー/アンフォローイベントを送信
      await UnifiedAnalyticsService.sendEvent(
        type: 'follow_toggle',
        countdownId: targetUserId, // targetUserIdをcountdownIdとして送信
        eventData: {
          'action': 'toggle', // サーバー側で現在の状態を確認して決定
          'targetUserId': targetUserId,
        },
      );

      print('FollowService - Toggle follow sent for user: $targetUserId');
    } catch (e) {
      print('FollowService - Error toggling follow: $e');
      rethrow;
    }
  }

  static Future<bool> isFollowing(String targetUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final response = await MVPAnalyticsClient.getUserState(
        user.uid,
        targetUserId,
      );
      
      return response['is_following'] ?? false;
    } catch (e) {
      print('FollowService - Error checking follow state: $e');
      return false;
    }
  }

  static Future<Map<String, int>> getFollowCounts(String userId) async {
    try {
      final response = await MVPAnalyticsClient.getUserFollows(userId);
      return response['follow_counts'] ?? {'following': 0, 'followers': 0};
    } catch (e) {
      print('FollowService - Error getting follow counts: $e');
      return {'following': 0, 'followers': 0};
    }
  }

  static Future<List<String>> getFollowers(String userId) async {
    try {
      final response = await MVPAnalyticsClient.getFollowers(userId);
      return List<String>.from(response['followers'] ?? []);
    } catch (e) {
      print('FollowService - Error getting followers: $e');
      return [];
    }
  }
}