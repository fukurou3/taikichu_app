import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'scalable_trend_service.dart';

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
        'viewedAt': Timestamp.fromDate(now), // フィールド名を統一
        'timestamp': Timestamp.fromDate(now),
        'userAgent': 'Flutter App', // アプリ識別用
      });

      // 最近の閲覧用レコードも作成（24時間後に自動削除）
      await _firestore.collection(_recentViewsCollection).add({
        'countdownId': countdownId,
        'userId': userId,
        'viewedAt': Timestamp.fromDate(now), // フィールド名を統一
        'timestamp': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      });

      // ローカルキャッシュを更新
      _recentViews[viewKey] = now;

      // トレンドスコア更新（非同期・エラーでも影響しない）
      ScalableTrendService.updateTrendScoreOnAction(
        countdownId: countdownId,
        actionType: 'view',
        increment: 1,
      ).catchError((e) {
        print('Error updating trend score for view: $e');
      });

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
          .where('viewedAt', isGreaterThan: Timestamp.fromDate(yesterday))
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
          .where('viewedAt', isGreaterThan: Timestamp.fromDate(yesterday))
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

  /// 【安全版】古い閲覧レコードを削除（定期実行用・スケーラブル版）
  /// 
  /// ⚠️ 修正版: バッチサイズを小さくして高コストを防ぐ
  static Future<void> cleanupOldViews({
    int daysToKeep = 30,
    int batchSize = 100, // 🎯 500→100に削減してコスト抑制
    int maxOperations = 1000, // 🚨 最大処理数制限を追加
  }) async {
    try {
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: daysToKeep));
      var totalDeleted = 0;

      print('ViewTrackingService - Starting cleanup of views older than $daysToKeep days...');

      // 1. 古い一般閲覧記録を削除（バッチ処理・制限付き）
      final deleted1 = await _cleanupCollectionBatchedSafe(
        _collection,
        'viewedAt',
        cutoffDate,
        batchSize,
        maxOperations ~/ 2, // 最大処理数の半分
      );
      totalDeleted += deleted1;

      // 2. 期限切れの最近閲覧記録を削除（制限付き）
      final deleted2 = await _cleanupCollectionBatchedSafe(
        _recentViewsCollection,
        'expiresAt',
        now,
        batchSize,
        maxOperations - deleted1, // 残りの処理数
      );
      totalDeleted += deleted2;

      print('ViewTrackingService - Cleanup completed. Total deleted: $totalDeleted');
    } catch (e) {
      print('ViewTrackingService - Error cleaning up old views: $e');
    }
  }

  /// 【安全版】バッチ処理で大量のドキュメントを効率的に削除
  /// 
  /// 🚨 最大処理数制限を追加してコスト爆発を防ぐ
  static Future<int> _cleanupCollectionBatchedSafe(
    String collectionName,
    String timestampField,
    DateTime cutoffDate,
    int batchSize,
    int maxOperations,
  ) async {
    var totalDeleted = 0;
    var operationCount = 0;
    
    print('ViewTrackingService - Starting cleanup of $collectionName (max: $maxOperations ops)');
    
    while (operationCount < maxOperations) {
      final remainingOps = maxOperations - operationCount;
      final currentBatchSize = batchSize < remainingOps ? batchSize : remainingOps;
      
      final query = _firestore
          .collection(collectionName)
          .where(timestampField, isLessThan: Timestamp.fromDate(cutoffDate))
          .limit(currentBatchSize);

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        print('ViewTrackingService - No more documents to delete in $collectionName');
        break;
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      totalDeleted += snapshot.docs.length;
      operationCount += snapshot.docs.length;
      
      print('ViewTrackingService - Deleted ${snapshot.docs.length} docs from $collectionName (total: $totalDeleted)');
      
      // 最大処理数に達した場合は停止
      if (operationCount >= maxOperations) {
        print('ViewTrackingService - Reached max operations limit ($maxOperations) for $collectionName');
        break;
      }
      
      // Firestore書き込み制限回避のため短い待機
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return totalDeleted;
  }

  /// 重複した閲覧記録の統合（データ最適化）
  static Future<void> consolidateDuplicateViews({
    int consolidationWindowMinutes = 60,
    int batchSize = 100,
  }) async {
    try {
      print('ViewTrackingService - Starting duplicate view consolidation...');
      
      final windowDuration = Duration(minutes: consolidationWindowMinutes);
      final now = DateTime.now();
      final recentCutoff = now.subtract(const Duration(hours: 24));
      
      // 最近24時間の閲覧記録を対象に重複を統合
      final snapshot = await _firestore
          .collection(_recentViewsCollection)
          .where('viewedAt', isGreaterThan: Timestamp.fromDate(recentCutoff))
          .orderBy('viewedAt', descending: true)
          .get();

      // ユーザー×カウントダウンでグループ化
      final groupedViews = <String, List<QueryDocumentSnapshot>>{};
      
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final userId = data['userId'] as String;
        final countdownId = data['countdownId'] as String;
        final key = '${userId}_$countdownId';
        
        groupedViews.putIfAbsent(key, () => []);
        groupedViews[key]!.add(doc);
      }

      var totalConsolidated = 0;
      
      // 各グループで重複を統合
      for (final entry in groupedViews.entries) {
        final views = entry.value;
        if (views.length <= 1) continue;

        // 時間順にソート（新しい順）
        views.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = (aData['viewedAt'] as Timestamp).toDate();
          final bTime = (bData['viewedAt'] as Timestamp).toDate();
          return bTime.compareTo(aTime);
        });

        // 統合対象を特定（時間窓内の重複）
        final toDelete = <QueryDocumentSnapshot>[];
        DateTime? lastViewTime;

        for (final view in views) {
          final viewData = view.data() as Map<String, dynamic>;
          final viewTime = (viewData['viewedAt'] as Timestamp).toDate();
          
          if (lastViewTime != null && 
              lastViewTime.difference(viewTime).abs() < windowDuration) {
            toDelete.add(view);
          } else {
            lastViewTime = viewTime;
          }
        }

        // バッチ削除
        if (toDelete.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in toDelete) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          
          totalConsolidated += toDelete.length;
        }
      }

      print('ViewTrackingService - Consolidation completed. Total consolidated: $totalConsolidated');
    } catch (e) {
      print('ViewTrackingService - Error during consolidation: $e');
    }
  }

  /// ローカルキャッシュをクリア
  static void clearLocalCache() {
    _recentViews.clear();
  }
}