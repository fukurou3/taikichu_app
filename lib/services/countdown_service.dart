import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';
import 'unified_analytics_service.dart';

class CountdownService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'counts';

  static Stream<List<Countdown>> getCountdownsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('eventDate', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Countdown.fromFirestore(doc, null);
      }).toList();
    });
  }

  /// 【非推奨】直接カウントダウン作成
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use UnifiedAnalyticsService.sendEvent() instead')
  static Future<void> addCountdown(Countdown countdown) async {
    throw UnimplementedError('Direct countdown creation disabled for security - use unified pipeline');
  }

  /// 【統一パイプライン】カウントダウン作成イベント送信
  static Future<bool> createCountdownEvent(Countdown countdown) async {
    try {
      return await UnifiedAnalyticsService.sendEvent(
        type: 'countdown_created',
        countdownId: countdown.id,
        metadata: {
          'eventName': countdown.eventName,
          'eventDate': countdown.eventDate.toIso8601String(),
          'creatorId': countdown.creatorId,
          'hashtags': countdown.hashtags,
          'description': countdown.description,
        },
      );
    } catch (e) {
      print('CountdownService - Error creating countdown event: $e');
      return false;
    }
  }

  /// 【非推奨】直接参加者数更新
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use UnifiedAnalyticsService.sendParticipationEvent() instead')
  static Future<void> updateParticipantsCount(String countdownId, int newCount) async {
    throw UnimplementedError('Direct counts update disabled for security - use unified pipeline');
  }

  /// 【非推奨】直接いいね数更新
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use UnifiedAnalyticsService.sendLikeEvent() instead')
  static Future<void> updateLikesCount(String countdownId, int increment) async {
    throw UnimplementedError('Direct counts update disabled for security - use unified pipeline');
  }

  /// 【非推奨】直接コメント数更新
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use UnifiedAnalyticsService.sendCommentEvent() instead')
  static Future<void> updateCommentsCount(String countdownId, int increment) async {
    throw UnimplementedError('Direct counts update disabled for security - use unified pipeline');
  }

  /// 【非推奨】直接カウントダウン削除
  /// ⚠️ 統一パイプライン移行後は使用禁止
  @Deprecated('Use UnifiedAnalyticsService.sendEvent() instead')
  static Future<void> deleteCountdown(String countdownId) async {
    throw UnimplementedError('Direct countdown deletion disabled for security - use unified pipeline');
  }

  /// 【統一パイプライン】カウントダウン削除イベント送信
  static Future<bool> deleteCountdownEvent(String countdownId) async {
    try {
      return await UnifiedAnalyticsService.sendEvent(
        type: 'countdown_deleted',
        countdownId: countdownId,
        metadata: {'reason': 'user_request'},
      );
    } catch (e) {
      print('CountdownService - Error deleting countdown event: $e');
      return false;
    }
  }
}