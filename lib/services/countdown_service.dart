// Simplified Countdown Service for Phase0 v2.1
// Direct Firestore operations with Write Fan-out

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/countdown.dart';
import 'simple_firestore_service.dart';

class CountdownService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// カウントダウンストリーム取得（近日中のイベント）
  static Stream<List<Countdown>> getCountdownsStream() {
    return _firestore
        .collection('posts')
        .where('status', isEqualTo: 'visible')
        .where('eventDate', isGreaterThan: DateTime.now())
        .orderBy('eventDate', descending: false)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Countdown.fromFirestore(doc);
      }).toList();
    });
  }

  /// カウントダウン作成（Write Fan-out付き）
  static Future<bool> createCountdownEvent(Countdown countdown) async {
    try {
      // SimpleFirestoreService経由で作成（Fan-out実行）
      await SimpleFirestoreService.createPost(countdown);
      
      print('CountdownService - Created countdown: ${countdown.id}');
      return true;
    } catch (e) {
      print('CountdownService - Error creating countdown: $e');
      return false;
    }
  }

  /// カテゴリ別のカウントダウン取得
  static Future<List<Countdown>> getCountdownsByCategory(String category, {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('category', isEqualTo: category)
          .where('status', isEqualTo: 'visible')
          .where('eventDate', isGreaterThan: DateTime.now())
          .orderBy('eventDate', descending: false)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => Countdown.fromFirestore(doc)).toList();
    } catch (e) {
      print('CountdownService - Error getting countdowns by category: $e');
      return [];
    }
  }

  /// 人気のカウントダウン取得
  static Future<List<Countdown>> getPopularCountdowns({int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('status', isEqualTo: 'visible')
          .where('eventDate', isGreaterThan: DateTime.now())
          .orderBy('likesCount', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => Countdown.fromFirestore(doc)).toList();
    } catch (e) {
      print('CountdownService - Error getting popular countdowns: $e');
      return [];
    }
  }

  /// カウントダウン検索
  static Future<List<Countdown>> searchCountdowns(String query, {int limit = 20}) async {
    return await SimpleFirestoreService.searchPosts(query, limit: limit);
  }

  /// 特定のカウントダウン取得
  static Future<Countdown?> getCountdown(String countdownId) async {
    try {
      final doc = await _firestore.collection('posts').doc(countdownId).get();
      
      if (doc.exists) {
        return Countdown.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('CountdownService - Error getting countdown: $e');
      return null;
    }
  }

  /// カウントダウン削除（ソフト削除）
  static Future<bool> deleteCountdown(String countdownId) async {
    try {
      await _firestore.collection('posts').doc(countdownId).update({
        'status': 'deleted_by_user',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('CountdownService - Deleted countdown: $countdownId');
      return true;
    } catch (e) {
      print('CountdownService - Error deleting countdown: $e');
      return false;
    }
  }

  /// 期限切れのカウントダウン取得（参考用）
  static Future<List<Countdown>> getExpiredCountdowns({int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('posts')
          .where('status', isEqualTo: 'visible')
          .where('eventDate', isLessThan: DateTime.now())
          .orderBy('eventDate', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => Countdown.fromFirestore(doc)).toList();
    } catch (e) {
      print('CountdownService - Error getting expired countdowns: $e');
      return [];
    }
  }
}