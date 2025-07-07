import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';

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

  static Future<void> addCountdown(Countdown countdown) async {
    await _firestore.collection(_collection).add(countdown.toFirestore());
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

  static Future<void> deleteCountdown(String countdownId) async {
    await _firestore.collection(_collection).doc(countdownId).delete();
  }
}