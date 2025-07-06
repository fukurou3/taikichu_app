import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ViewTrackingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'views';
  static const String _recentViewsCollection = 'recentViews';
  
  // 短期間の重複閲覧を防ぐためのローカルキャッシュ
  static final Map<String, DateTime> _recentViews = {};
  static const int _viewCooldownSeconds = 30; // 30秒以内の重複閲覧は無視

  /// カウントダウンの閲覧を記録
  static Future<void> trackView(String countdownId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final viewKey = '${countdownId}_$userId';
    final now = DateTime.now();

    // ローカルキャッシュでクールダウンチェック
    final lastView = _recentViews[viewKey];
    if (lastView != null && 
        now.difference(lastView).inSeconds < _viewCooldownSeconds) {
      return; // クールダウン中は無視
    }

    try {
      // 閲覧記録を保存
      await _firestore.collection(_collection).add({
        'countdownId': countdownId,
        'userId': userId,
        'timestamp': Timestamp.fromDate(now),
        'userAgent': 'Flutter App', // アプリ識別用
      });

      // 最近の閲覧用レコードも作成（24時間後に自動削除）
      await _firestore.collection(_recentViewsCollection).add({
        'countdownId': countdownId,
        'userId': userId,
        'timestamp': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      });

      // ローカルキャッシュを更新
      _recentViews[viewKey] = now;

      print('View tracked for countdown: $countdownId by user: $userId');
    } catch (e) {
      print('Error tracking view: $e');
    }
  }

  /// ユニーク閲覧数を取得
  static Future<int> getUniqueViewsCount(String countdownId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('countdownId', isEqualTo: countdownId)
          .get();

      // ユニークユーザー数を計算
      final uniqueUsers = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        uniqueUsers.add(data['userId'] as String);
      }

      return uniqueUsers.length;
    } catch (e) {
      print('Error getting unique views count: $e');
      return 0;
    }
  }

  /// 最近24時間の閲覧数を取得
  static Future<int> getRecentViewsCount(String countdownId) async {
    try {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));

      final snapshot = await _firestore
          .collection(_recentViewsCollection)
          .where('countdownId', isEqualTo: countdownId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(yesterday))
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('Error getting recent views count: $e');
      return 0;
    }
  }

  /// 人気のカウントダウンを取得（閲覧数順）
  static Future<List<String>> getPopularCountdowns({int limit = 10}) async {
    try {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));

      final snapshot = await _firestore
          .collection(_recentViewsCollection)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(yesterday))
          .get();

      // カウントダウンごとの閲覧数を集計
      final viewCounts = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final countdownId = data['countdownId'] as String;
        viewCounts[countdownId] = (viewCounts[countdownId] ?? 0) + 1;
      }

      // 閲覧数順にソート
      final sortedEntries = viewCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedEntries
          .take(limit)
          .map((entry) => entry.key)
          .toList();
    } catch (e) {
      print('Error getting popular countdowns: $e');
      return [];
    }
  }

  /// 古い閲覧レコードを削除（定期実行用）
  static Future<void> cleanupOldViews() async {
    try {
      final now = DateTime.now();
      final oneMonthAgo = now.subtract(const Duration(days: 30));

      // 1ヶ月以上古い一般閲覧記録を削除
      final oldViewsSnapshot = await _firestore
          .collection(_collection)
          .where('timestamp', isLessThan: Timestamp.fromDate(oneMonthAgo))
          .get();

      final batch = _firestore.batch();
      for (final doc in oldViewsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 期限切れの最近閲覧記録を削除
      final expiredRecentViewsSnapshot = await _firestore
          .collection(_recentViewsCollection)
          .where('expiresAt', isLessThan: Timestamp.fromDate(now))
          .get();

      for (final doc in expiredRecentViewsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('Cleaned up old view records');
    } catch (e) {
      print('Error cleaning up old views: $e');
    }
  }

  /// ローカルキャッシュをクリア
  static void clearLocalCache() {
    _recentViews.clear();
  }
}