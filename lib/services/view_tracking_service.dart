import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'unified_analytics_service.dart';
import 'mvp_analytics_client.dart';

class ViewTrackingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'views';
  static const String _recentViewsCollection = 'recentViews';
  
  // 短期間の重複閲覧を防ぐためのローカルキャッシュ
  static final Map<String, DateTime> _recentViews = {};
  static const int _viewCooldownSeconds = 30; // 30秒以内の重複閲覧は無視

  /// 【統一パイプライン】カウントダウンの閲覧を記録
  /// 
  /// 🚀 クライアントはイベント発行のみ、Firestore更新はサーバーサイドで実行
  /// 💡 二重書き込み問題を解決し、データ整合性を保証
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
      // 🚀 統一パイプラインへイベントを送信するだけ！
      // Firestore更新はサーバーサイド（Cloud Run）で実行される
      final success = await UnifiedAnalyticsService.sendViewEvent(
        countdownId,
        viewMetadata: {
          'source_screen': 'home', // 閲覧元画面
          'user_agent': 'Flutter App',
          'view_duration': 0, // 実際の閲覧時間は別途計測
          'session_id': UnifiedAnalyticsService.sessionId,
        },
      );
      
      if (!success) {
        throw Exception('閲覧イベントの送信に失敗しました');
      }
      
      // ローカルキャッシュを更新（UI即時反映用）
      _recentViews[viewKey] = now;

      print('View event sent for countdown: $countdownId by user: $userId');
    } catch (e) {
      print('Error sending view event: $e');
    }
  }

  /// 【統一パイプライン】ユニーク閲覧数を取得
  /// 
  /// 🚀 Redis経由で高速データ取得
  /// ⚠️ Firestore直接アクセスは禁止
  static Future<int> getUniqueViewsCount(String countdownId) async {
    try {
      return await MVPAnalyticsClient.getCounterValue(
        countdownId: countdownId,
        counterType: 'views',
      );
    } catch (e) {
      print('Error getting unique views count: $e');
      return 0;
    }
  }

  /// 【統一パイプライン】最近24時間の閲覧数を取得
  /// 
  /// 🚀 Redis経由で高速データ取得
  /// ⚠️ Firestore直接アクセスは禁止
  static Future<int> getRecentViewsCount(String countdownId) async {
    try {
      return await MVPAnalyticsClient.getCounterValue(
        countdownId: countdownId,
        counterType: 'recentViews',
      );
    } catch (e) {
      print('Error getting recent views count: $e');
      return 0;
    }
  }

  /// 【統一パイプライン】人気のカウントダウンを取得（閲覧数順）
  /// 
  /// 🚀 Redis経由で高速データ取得
  /// ⚠️ Firestore直接アクセスは禁止
  static Future<List<String>> getPopularCountdowns({int limit = 10}) async {
    try {
      // 🚀 統一パイプライン: Cloud Run API経由で人気カウントダウン取得
      // TODO: MVPAnalyticsClientにgetPopularCountdowns APIを追加
      // 現時点では統一パイプラインでランキング取得を実装
      return [];
    } catch (e) {
      print('Error getting popular countdowns: $e');
      return [];
    }
  }

  /// 【非推奨】レガシー用クリーンアップ機能
  /// 
  /// ⚠️ 統一パイプライン移行後は使用禁止
  /// ⚠️ サーバーサイドで自動実行される
  @Deprecated('Legacy cleanup disabled - now handled by server-side pipeline')
  static Future<void> cleanupOldViews({
    int daysToKeep = 30,
    int batchSize = 100,
    int maxOperations = 1000,
  }) async {
    throw UnimplementedError('Legacy cleanup disabled for security - handled by server-side pipeline');
  }

  /// 【非推奨】レガシー用重複統合機能
  /// 
  /// ⚠️ 統一パイプライン移行後は使用禁止
  /// ⚠️ サーバーサイドで自動実行される
  @Deprecated('Legacy consolidation disabled - now handled by server-side pipeline')
  static Future<void> consolidateDuplicateViews({
    int consolidationWindowMinutes = 60,
    int batchSize = 100,
  }) async {
    throw UnimplementedError('Legacy consolidation disabled for security - handled by server-side pipeline');
  }

  /// 【非推奨】レガシー用内部処理
  @Deprecated('Legacy internal method disabled')
  static Future<int> _cleanupCollectionBatchedSafe(
    String collectionName,
    String timestampField,
    DateTime cutoffDate,
    int batchSize,
    int maxOperations,
  ) async {
    throw UnimplementedError('Legacy internal method disabled for security');
  }

  /// ローカルキャッシュをクリア
  static void clearLocalCache() {
    _recentViews.clear();
  }
}