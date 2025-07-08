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


  /// 【統一パイプライン】カウントダウン作成（Firestore書き込み + ファンアウト）
  static Future<bool> createCountdownEvent(Countdown countdown) async {
    try {
      // 1. Firestoreにドキュメントを作成
      final docRef = await _firestore.collection(_collection).add({
        'eventName': countdown.eventName,
        'description': countdown.description,
        'eventDate': Timestamp.fromDate(countdown.eventDate),
        'category': countdown.category,
        'creatorId': countdown.creatorId,
        'hashtags': countdown.hashtags,
        'imageUrl': countdown.imageUrl,
        'status': 'visible',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final countdownId = docRef.id;
      print('CountdownService - Created countdown with ID: $countdownId');

      // 2. ファンアウト処理：統一パイプライン経由でカウントダウン作成イベント送信
      final eventSuccess = await UnifiedAnalyticsService.sendCountdownCreatedEvent(
        countdownId,
        countdownData: {
          'eventName': countdown.eventName,
          'eventDate': countdown.eventDate.toIso8601String(),
          'creatorId': countdown.creatorId,
          'category': countdown.category,
        },
      );

      if (!eventSuccess) {
        print('CountdownService - Warning: Event sending failed, but document created');
      }

      return true;
    } catch (e) {
      print('CountdownService - Error creating countdown: $e');
      return false;
    }
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